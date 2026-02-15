import Foundation

// ============================================================================
// FILE: TaskConditionerParser.swift
// PURPOSE: Evaluates task conditions against user assessment data
// FORMAT: Conditions are [String: [String]] dictionaries from Firestore
//
// CONDITION FORMAT (from TaskCatalogSchema.swift):
//   - Key: Assessment field name (e.g., "AnyPets", "MoveDistance")
//   - Value: Array of acceptable values (OR logic within array)
//   - Multiple keys: AND logic (all must match)
//
// EXAMPLES:
//   {"AnyPets": ["Yes"]} → User's AnyPets must be "Yes"
//   {"MoveDistance": ["Long Distance", "Cross-Country"]} → Either value matches
//   {"AnyPets": ["Yes"], "MoveDistance": ["Long Distance"]} → Both must match
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
            print("    ✅ No conditions - auto-pass")
            return true
        }

        print("    📋 Evaluating \(conditions.count) condition(s)...")

        // ALL conditions must pass (AND logic)
        for (fieldName, acceptableValues) in conditions {

            // Get the array of acceptable values
            guard let valuesArray = acceptableValues as? [String], !valuesArray.isEmpty else {
                print("    ⚠️ Invalid condition format for '\(fieldName)' - skipping")
                continue
            }

            // Get user's value for this field
            let userValue = userAssessment[fieldName]

            // Check if user's value matches any acceptable value (OR logic within array)
            let matches = checkValueMatches(userValue: userValue, acceptableValues: valuesArray, fieldName: fieldName)

            if !matches {
                print("    ❌ FAILED: '\(fieldName)' - user has '\(userValue ?? "nil")' but needs one of \(valuesArray)")
                return false
            }

            print("    ✅ PASSED: '\(fieldName)' = '\(userValue ?? "nil")' matches \(valuesArray)")
        }

        print("    ✅ All conditions passed!")
        return true
    }

    // MARK: - Value Matching

    /// Checks if user's value matches any of the acceptable values
    private static func checkValueMatches(userValue: Any?, acceptableValues: [String], fieldName: String) -> Bool {

        // Handle nil user value
        guard let userValue = userValue else {
            // Check if "nil" or empty is acceptable
            return acceptableValues.contains { $0.lowercased() == "nil" || $0.isEmpty }
        }

        // Convert user value to string for comparison
        let userValueString = stringValue(from: userValue)

        // Check each acceptable value
        for acceptable in acceptableValues {
            if matchesValue(userString: userValueString, acceptable: acceptable) {
                return true
            }
        }

        return false
    }

    /// Converts any value to string for comparison
    private static func stringValue(from value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "Yes" : "No"  // Convert Bool to Yes/No format
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
        if acceptable.hasPrefix(">=") {
            return handleNumericComparison(userString: userString, comparison: acceptable)
        }

        if acceptable.hasPrefix("<=") {
            return handleNumericComparison(userString: userString, comparison: acceptable)
        }

        if acceptable.hasPrefix(">") && !acceptable.hasPrefix(">=") {
            return handleNumericComparison(userString: userString, comparison: acceptable)
        }

        if acceptable.hasPrefix("<") && !acceptable.hasPrefix("<=") {
            return handleNumericComparison(userString: userString, comparison: acceptable)
        }

        // Case-insensitive string comparison
        return userString.lowercased() == acceptable.lowercased()
    }

    /// Handles numeric comparisons like ">=1", "<=5", ">0", "<10"
    private static func handleNumericComparison(userString: String, comparison: String) -> Bool {

        // Extract the number from comparison string
        var operatorStr = ""
        var numberStr = comparison

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
        }

        guard let threshold = Int(numberStr) else {
            print("    ⚠️ Invalid numeric comparison: '\(comparison)'")
            return false
        }

        // Try to convert user value to number
        guard let userNumber = Int(userString) else {
            // User value isn't a number - can't compare
            return false
        }

        // Perform comparison
        switch operatorStr {
        case ">=": return userNumber >= threshold
        case "<=": return userNumber <= threshold
        case ">":  return userNumber > threshold
        case "<":  return userNumber < threshold
        default:   return false
        }
    }

    // MARK: - Legacy Support (for string-format conditions if any remain)

    /// Converts old string format conditions to new dictionary format
    /// Old format: "fieldName: value, otherField: value"
    /// New format: ["fieldName": ["value"], "otherField": ["value"]]
    static func convertLegacyConditions(_ legacyString: String) -> [String: [String]] {
        var result: [String: [String]] = [:]

        let pairs = legacyString.components(separatedBy: ",")
        for pair in pairs {
            let parts = pair.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                let field = parts[0]
                let value = parts[1]
                result[field] = [value]
            }
        }

        return result
    }
}
