// TaskConditionParser.swift
// Peezy iOS - Task Condition Evaluation
// Evaluates task conditions against user assessment data

import Foundation

class TaskConditionParser {
    
    /// Evaluates whether a task's conditions match the user's assessment
    /// - Parameters:
    ///   - conditions: The condition string from task catalog (e.g., "MoveDistance: Local, Gym: Yes")
    ///   - userAssessment: Dictionary containing user's assessment data
    /// - Returns: true if conditions are met (task should be generated), false otherwise
    static func evaluateConditions(_ conditions: String?, against userAssessment: [String: Any]) -> Bool {
        // If no conditions, always generate task
        guard let conditions = conditions, !conditions.isEmpty else {
            return true
        }
        
        // Parse conditions into field groups
        let conditionMap = parseConditions(conditions)
        
        // Check each field condition (AND logic between fields)
        for (fieldName, acceptableValues) in conditionMap {
            let userValue = userAssessment[fieldName]
            
            // Check if user's value matches any acceptable value (OR logic within field)
            var fieldMatches = false
            for acceptableValue in acceptableValues {
                if checkValueMatch(userValue: userValue, acceptableValue: acceptableValue) {
                    fieldMatches = true
                    break
                }
            }
            
            // If any field doesn't match, return false
            if !fieldMatches {
                return false
            }
        }
        
        // All conditions met
        return true
    }
    
    // MARK: - Private Helpers
    
    /// Parses condition string into dictionary of field names and acceptable values
    /// Example: "MoveDistance: Local, Cross-Country, Gym: Yes"
    /// Returns: ["moveDistance": ["Local", "Cross-Country"], "gym": ["Yes"]]
    private static func parseConditions(_ conditions: String) -> [String: [String]] {
        var conditionMap: [String: [String]] = [:]
        
        // Split by comma to get individual field conditions
        let fieldConditions = conditions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for condition in fieldConditions {
            guard condition.contains(":") else { continue }
            
            let parts = condition.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let fieldName = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let fieldValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            // Convert to camelCase (e.g., "MoveDistance" -> "moveDistance")
            let assessmentFieldName = fieldName.prefix(1).lowercased() + fieldName.dropFirst()
            
            if conditionMap[assessmentFieldName] == nil {
                conditionMap[assessmentFieldName] = []
            }
            conditionMap[assessmentFieldName]?.append(fieldValue)
        }
        
        return conditionMap
    }
    
    /// Checks if user's value matches an acceptable value
    /// Handles comparison operators (>=, <=, >, <), booleans, and strings
    private static func checkValueMatch(userValue: Any?, acceptableValue: String) -> Bool {
        // Handle nil user values
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
    
    /// Extracts number from condition string (e.g., ">=1" -> 1.0)
    private static func extractNumber(from string: String, offset: Int) -> Double? {
        let numString = String(string.dropFirst(offset)).trimmingCharacters(in: .whitespaces)
        return Double(numString)
    }
    
    /// Converts any value to number if possible
    private static func toNumber(_ value: Any) -> Double? {
        if let num = value as? Double {
            return num
        }
        if let num = value as? Int {
            return Double(num)
        }
        if let num = value as? Float {
            return Double(num)
        }
        if let string = value as? String, let num = Double(string) {
            return num
        }
        return nil
    }
}

// MARK: - Usage Examples

/*
 
 // Example 1: Simple match
 let conditions = "MoveDistance: Long Distance, Cross-Country"
 let assessment = ["moveDistance": "Long Distance"]
 let result = TaskConditionParser.evaluateConditions(conditions, against: assessment)
 // Returns: true
 
 // Example 2: Multiple fields (AND logic)
 let conditions = "MoveDistance: Local, Gym: Yes"
 let assessment = ["moveDistance": "Local", "gym": "Yes"]
 let result = TaskConditionParser.evaluateConditions(conditions, against: assessment)
 // Returns: true
 
 // Example 3: Numeric comparison
 let conditions = "SchoolAgeChildren: >=1"
 let assessment = ["schoolAgeChildren": 2]
 let result = TaskConditionParser.evaluateConditions(conditions, against: assessment)
 // Returns: true
 
 // Example 4: Failed match
 let conditions = "MoveDistance: Local, Gym: Yes"
 let assessment = ["moveDistance": "Local", "gym": "No"]
 let result = TaskConditionParser.evaluateConditions(conditions, against: assessment)
 // Returns: false
 
 */
