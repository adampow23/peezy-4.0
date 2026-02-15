#!/usr/bin/env swift
// FILE: Tests/ConditionVerification.swift
// PURPOSE: Verify condition parsing works with REAL Firestore formats
// NOTE: This file is for verification only - DELETE BEFORE SHIPPING
//
// REAL CONDITION FORMATS FOUND IN CODEBASE:
// From functions/vendorCatalog.js:
//   - conditions: []                                    (empty array)
//   - conditions: ['moveDistance: cross_state', 'moveDistance: cross_country']
//   - conditions: ['needsStorage: true', 'dateGap > 0']
//   - conditions: ['hasPets: true', 'moveDistance: cross_state+']
//   - conditions: ['hasKids: true']
//   - conditions: ['destinationOwnership: own']
//   - conditions: ['destinationOwnership: own', 'destinationPropertyType: house']
//
// From functions/workflows.js:
//   - conditions: ['hasPets: true']
//   - conditions: ['needsStorage: true', 'dateGap']
//   - conditions: ['ownership: own', 'propertyType: house/townhouse']
//   - conditions: ['moveDistance: cross_country', 'hasVehicle: true']
//   - conditions: ['hasKids: true']
//   - conditions: ['originOwnership: rent']
//   - conditions: ['destinationOwnership: own']

import Foundation

// ============================================
// EXACT COPY of TaskConditionParser (lines 7-167 of TaskConditionerParser.swift)
// ============================================

class TaskConditionParser {

    static func evaluateConditions(_ conditions: String?, against userAssessment: [String: Any]) -> Bool {
        guard let conditions = conditions, !conditions.isEmpty else {
            return true
        }

        let conditionMap = parseConditions(conditions)

        for (fieldName, acceptableValues) in conditionMap {
            let userValue = userAssessment[fieldName]

            var fieldMatches = false
            for acceptableValue in acceptableValues {
                let matches = checkValueMatch(userValue: userValue, acceptableValue: acceptableValue)
                if matches {
                    fieldMatches = true
                    break
                }
            }

            if !fieldMatches {
                return false
            }
        }

        return true
    }

    private static func parseConditions(_ conditions: String) -> [String: [String]] {
        var conditionMap: [String: [String]] = [:]

        let fieldConditions = conditions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for condition in fieldConditions {
            guard condition.contains(":") else { continue }

            let parts = condition.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let fieldName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let fieldValue = String(parts[1]).trimmingCharacters(in: .whitespaces)

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

// ============================================
// EXACT COPY of condition extraction logic (lines 50-62 of TaskGenerationService.swift)
// ============================================

func extractConditions(from taskData: [String: Any]) -> String? {
    // Get conditions - handle both String and Array formats from Firestore
    if let conditionString = taskData["conditions"] as? String {
        return conditionString
    } else if let conditionArray = taskData["conditions"] as? [String] {
        // Convert array to comma-separated string
        return conditionArray.joined(separator: ", ")
    } else {
        return nil
    }
}

// ============================================
// TEST DATA: REAL formats found in vendorCatalog.js and workflows.js
// ============================================

struct TestCase {
    let name: String
    let taskConditions: Any  // Can be String, [String], or nil (empty)
    let userAssessment: [String: Any]
    let expectedResult: Bool
}

let testCases: [TestCase] = [
    // Empty conditions - should always pass
    TestCase(
        name: "Empty array conditions (vendorCatalog.js line 20)",
        taskConditions: [] as [String],
        userAssessment: ["hasKids": false, "hasPets": false],
        expectedResult: true
    ),

    // hasKids: true condition - REAL format from workflows.js line 564
    TestCase(
        name: "hasKids: true - user HAS kids (should PASS)",
        taskConditions: ["hasKids: true"],
        userAssessment: ["hasKids": true],
        expectedResult: true
    ),
    TestCase(
        name: "hasKids: true - user has NO kids (should FAIL)",
        taskConditions: ["hasKids: true"],
        userAssessment: ["hasKids": false],
        expectedResult: false
    ),

    // hasPets: true condition - REAL format from vendorCatalog.js line 137
    TestCase(
        name: "hasPets: true - user HAS pets (should PASS)",
        taskConditions: ["hasPets: true"],
        userAssessment: ["hasPets": true],
        expectedResult: true
    ),
    TestCase(
        name: "hasPets: true - user has NO pets (should FAIL)",
        taskConditions: ["hasPets: true"],
        userAssessment: ["hasPets": false],
        expectedResult: false
    ),

    // Multiple conditions with OR logic - REAL format from vendorCatalog.js line 36
    TestCase(
        name: "moveDistance: cross_state OR cross_country - user is cross_state (should PASS)",
        taskConditions: ["moveDistance: cross_state", "moveDistance: cross_country"],
        userAssessment: ["moveDistance": "cross_state"],
        expectedResult: true
    ),
    TestCase(
        name: "moveDistance: cross_state OR cross_country - user is local (should FAIL)",
        taskConditions: ["moveDistance: cross_state", "moveDistance: cross_country"],
        userAssessment: ["moveDistance": "local"],
        expectedResult: false
    ),

    // destinationOwnership condition - REAL format from workflows.js line 752
    TestCase(
        name: "destinationOwnership: own - user owns (should PASS)",
        taskConditions: ["destinationOwnership: own"],
        userAssessment: ["destinationOwnership": "own"],
        expectedResult: true
    ),
    TestCase(
        name: "destinationOwnership: own - user rents (should FAIL)",
        taskConditions: ["destinationOwnership: own"],
        userAssessment: ["destinationOwnership": "rent"],
        expectedResult: false
    ),

    // originOwnership condition - REAL format from workflows.js line 706
    TestCase(
        name: "originOwnership: rent - user rents origin (should PASS)",
        taskConditions: ["originOwnership: rent"],
        userAssessment: ["originOwnership": "rent"],
        expectedResult: true
    ),

    // Combined conditions AND logic - REAL format from vendorCatalog.js line 533
    TestCase(
        name: "destinationPropertyType: house AND destinationOwnership: own - both match (should PASS)",
        taskConditions: ["destinationPropertyType: house", "destinationOwnership: own"],
        userAssessment: ["destinationPropertyType": "house", "destinationOwnership": "own"],
        expectedResult: true
    ),
    TestCase(
        name: "destinationPropertyType: house AND destinationOwnership: own - only one matches (should FAIL)",
        taskConditions: ["destinationPropertyType: house", "destinationOwnership: own"],
        userAssessment: ["destinationPropertyType": "house", "destinationOwnership": "rent"],
        expectedResult: false
    ),

    // String format (legacy) - should also work
    TestCase(
        name: "String format: hasKids: true (legacy format)",
        taskConditions: "hasKids: true",
        userAssessment: ["hasKids": true],
        expectedResult: true
    ),

    // nil/missing conditions - should auto-pass
    TestCase(
        name: "nil conditions - should auto-pass",
        taskConditions: Optional<String>.none as Any,
        userAssessment: ["hasKids": false],
        expectedResult: true
    )
]

// ============================================
// RUN VERIFICATION
// ============================================

print("=" * 60)
print("CONDITION PARSING VERIFICATION")
print("Using REAL formats from vendorCatalog.js and workflows.js")
print("=" * 60)
print("")

var passed = 0
var failed = 0

for (index, test) in testCases.enumerated() {
    // Simulate extractConditions from taskData
    let taskData: [String: Any] = ["conditions": test.taskConditions]
    let extractedConditions = extractConditions(from: taskData)

    // Run parser
    let result = TaskConditionParser.evaluateConditions(extractedConditions, against: test.userAssessment)

    let status = result == test.expectedResult ? "PASS" : "FAIL"
    let icon = result == test.expectedResult ? "✅" : "❌"

    print("\(icon) Test \(index + 1): \(test.name)")
    print("   Conditions: \(test.taskConditions)")
    print("   Extracted:  \(extractedConditions ?? "nil/empty")")
    print("   User data:  \(test.userAssessment)")
    print("   Expected:   \(test.expectedResult), Got: \(result)")
    print("")

    if result == test.expectedResult {
        passed += 1
    } else {
        failed += 1
    }
}

print("=" * 60)
print("RESULTS: \(passed) passed, \(failed) failed out of \(testCases.count) tests")
print("=" * 60)

if failed > 0 {
    print("")
    print("⚠️  FAILURES DETECTED - Review failed tests above")
    exit(1)
} else {
    print("")
    print("✅ All tests passed - Condition parsing verified!")
    exit(0)
}

// Helper for string multiplication
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}
