import Foundation

// ============================================================================
// FILE: TaskConditionParser.swift
// PURPOSE: Evaluates task conditions against user assessment data
// FORMAT: Conditions are [String: [String]] dictionaries from Firestore
//
// LAST UPDATED: 2026-02-12
//
// CONDITION FORMAT (from TaskCatalogSchema.swift):
//   - Key: Assessment field name (e.g., "hasVet", "moveDistance")
//   - Value: Array of acceptable values (OR logic within array)
//   - Multiple keys: AND logic (all must match)
//
// EXAMPLES:
//   {"hasVet": ["Yes"]}                            → User's hasVet must be "Yes"
//   {"moveDistance": ["Long Distance"]}            → Must be long distance
//   {"isInterstate": ["Yes"]}                     → Must be changing states
//   {"hireMovers": ["Yes"]}                       → Interested in professional movers
//   {"fitnessWellness": ["Yoga"]}                 → User selected Yoga in multi-select
//   {"healthcareProviders": ["Doctor"], "moveDistance": ["Long Distance"]} → Both must match
//   {"financialInstitutions": ["Bank Account"], "moveDistance": ["Local"]} → Both must match
//
// VALUE TYPES:
//   User assessment values can be:
//     - String: "Yes", "Rent", "Apartment", "Local"
//     - Bool: true/false (converted to "Yes"/"No" for matching)
//     - Int/Double: numeric (used for >=1 comparisons)
//     - [String]: multi-select arrays like ["Yoga", "Gym", "Pilates"]
//
// MULTI-SELECT MATCHING:
//   For fields like fitnessWellness, healthcareProviders, financialInstitutions,
//   the user's data is an ARRAY of selected options. The condition specifies which
//   option(s) trigger this task. If ANY user selection matches ANY condition value,
//   the condition passes.
//
//   User data:  { fitnessWellness: ["Yoga", "Gym", "Pilates"] }
//   Condition:  { fitnessWellness: ["Yoga"] }
//   Result:     PASS — "Yoga" is in the user's selections
// ============================================================================

class TaskConditionParser {

    // MARK: - Main Evaluation Function

    /// Evaluates whether a task's conditions match the user's assessment
    /// - Parameters:
    ///   - conditions: Dictionary of field names to acceptable values, or nil
    ///   - userAssessment: User's assessment data dictionary
    /// - Returns: true if task should be generated, false if conditions not met
    static func evaluateConditions(_ conditions: [String: Any]?, against userAssessment: [String: Any]) -> Bool {

        // No conditions = task is for everyone
        guard let conditions = conditions, !conditions.isEmpty else {
            #if DEBUG
            print("    ✅ No conditions - auto-pass")
            #endif
            return true
        }

        #if DEBUG
        print("    📋 Evaluating \(conditions.count) condition(s)...")
        #endif

        // ALL conditions must pass (AND logic)
        for (fieldName, acceptableValues) in conditions {

            // Get the array of acceptable values
            guard let valuesArray = acceptableValues as? [String], !valuesArray.isEmpty else {
                #if DEBUG
                print("    ⚠️ Invalid condition format for '\(fieldName)' - skipping")
                #endif
                continue
            }

            // Get user's value for this field (case-insensitive key lookup)
            let userValue = userAssessment.first(where: { $0.key.lowercased() == fieldName.lowercased() })?.value

            // Check if user's value matches any acceptable value (OR logic within array)
            let matches = checkValueMatches(userValue: userValue, acceptableValues: valuesArray, fieldName: fieldName)

            if !matches {
                #if DEBUG
                print("    ❌ FAILED: '\(fieldName)' - user has '\(userValue ?? "nil")' but needs one of \(valuesArray)")
                #endif
                return false
            }

            #if DEBUG
            print("    ✅ PASSED: '\(fieldName)' = '\(userValue ?? "nil")' matches \(valuesArray)")
            #endif
        }

        #if DEBUG
        print("    ✅ All conditions passed!")
        #endif
        return true
    }

    // MARK: - Value Matching

    /// Checks if user's value matches any of the acceptable values
    /// Handles String, Bool, Int, Double, and [String] (multi-select) user values
    private static func checkValueMatches(userValue: Any?, acceptableValues: [String], fieldName: String) -> Bool {

        // Handle nil user value
        guard let userValue = userValue else {
            return acceptableValues.contains { $0.lowercased() == "nil" || $0.isEmpty }
        }

        // ── Multi-select array matching ──
        // For fields like fitnessWellness, healthcareProviders, financialInstitutions
        // User's value is an array of selected options
        // Check if ANY user selection matches ANY acceptable value
        if let userArray = userValue as? [String] {
            return userArray.contains { userItem in
                acceptableValues.contains { acceptable in
                    userItem.lowercased() == acceptable.lowercased()
                }
            }
        }

        // ── Single value matching ──
        let userValueString = stringValue(from: userValue)

        for acceptable in acceptableValues {
            if matchesValue(userString: userValueString, acceptable: acceptable) {
                return true
            }
        }

        return false
    }

    /// Converts any single value to string for comparison
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

    /// Compares user string value against an acceptable value
    private static func matchesValue(userString: String, acceptable: String) -> Bool {

        // Handle numeric comparisons (e.g., ">=1")
        if acceptable.hasPrefix(">=") || acceptable.hasPrefix("<=") ||
           (acceptable.hasPrefix(">") && !acceptable.hasPrefix(">=")) ||
           (acceptable.hasPrefix("<") && !acceptable.hasPrefix("<=")) {
            return handleNumericComparison(userString: userString, comparison: acceptable)
        }

        // Case-insensitive string comparison
        return userString.lowercased() == acceptable.lowercased()
    }

    /// Handles numeric comparisons like ">=1", "<=5", ">0", "<10"
    private static func handleNumericComparison(userString: String, comparison: String) -> Bool {

        let operatorStr: String
        let numberStr: String

        if comparison.hasPrefix(">=") {
            operatorStr = ">="
            numberStr = String(comparison.dropFirst(2))
        } else if comparison.hasPrefix("<=") {
            operatorStr = "<="
            numberStr = String(comparison.dropFirst(2))
        } else if comparison.hasPrefix(">") {
            operatorStr = ">"
            numberStr = String(comparison.dropFirst(1))
        } else if comparison.hasPrefix("<") {
            operatorStr = "<"
            numberStr = String(comparison.dropFirst(1))
        } else {
            return false
        }

        guard let threshold = Int(numberStr) else {
            #if DEBUG
            print("    ⚠️ Invalid numeric comparison: '\(comparison)'")
            #endif
            return false
        }

        guard let userNumber = Int(userString) else {
            return false
        }

        switch operatorStr {
        case ">=": return userNumber >= threshold
        case "<=": return userNumber <= threshold
        case ">":  return userNumber > threshold
        case "<":  return userNumber < threshold
        default:   return false
        }
    }
}
