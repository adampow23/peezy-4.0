#!/usr/bin/env swift
import Foundation

// ============================================================================
// TEST: Mini-Assessment -> Sub-Task Generation Flow
// ============================================================================

// Copy of TaskConditionParser logic for testing
class TaskConditionParser {
    static func evaluateConditions(_ conditions: [String: Any]?, against userAssessment: [String: Any]) -> Bool {
        guard let conditions = conditions, !conditions.isEmpty else { return true }
        for (fieldName, acceptableValues) in conditions {
            guard let valuesArray = acceptableValues as? [String], !valuesArray.isEmpty else { continue }
            guard let userValue = userAssessment[fieldName] else { return false }
            let userString = "\(userValue)"
            var matched = false
            for acceptable in valuesArray {
                if acceptable.hasPrefix(">=") {
                    if let threshold = Int(String(acceptable.dropFirst(2))), let userNum = Int(userString) {
                        if userNum >= threshold { matched = true; break }
                    }
                } else if userString.lowercased() == acceptable.lowercased() {
                    matched = true; break
                }
            }
            if !matched { return false }
        }
        return true
    }
}

// Simulated task catalog (from Firestore)
struct Task {
    let id: String
    let title: String
    let conditions: [String: [String]]
    let isSubTask: Bool
    let parentTask: String?
}

let taskCatalog: [Task] = [
    // Core tasks (not sub-tasks)
    Task(id: "FORWARD_MAIL", title: "Forward Mail", conditions: ["selectedMoveDate": ["true"]], isSubTask: false, parentTask: nil),
    Task(id: "BOOK_MOVERS", title: "Book Movers", conditions: ["HireMovers": ["Hire Movers"]], isSubTask: false, parentTask: nil),

    // Mini-assessment tasks (not sub-tasks, but trigger sub-task generation)
    Task(id: "CHILDREN_OPTIONS", title: "Children Mini-Assessment", conditions: ["WhosMoving": ["Family"]], isSubTask: false, parentTask: nil),
    Task(id: "PET_OPTIONS", title: "Pet Mini-Assessment", conditions: ["AnyPets": ["Yes"]], isSubTask: false, parentTask: nil),
    Task(id: "FITNESS_OPTIONS", title: "Fitness Mini-Assessment", conditions: ["selectedMoveDate": ["true"]], isSubTask: false, parentTask: nil),

    // Sub-tasks (generated AFTER mini-assessment completes)
    Task(id: "BEGIN_SCHOOL_TRANSFER", title: "Notify School of Transfer", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "SchoolAgeChildren": [">=1"]], isSubTask: true, parentTask: "CHILDREN_OPTIONS"),
    Task(id: "NEW_SCHOOL_ENROLLMENT", title: "Enroll in New School", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "SchoolAgeChildren": [">=1"]], isSubTask: true, parentTask: "CHILDREN_OPTIONS"),
    Task(id: "SETUP_VET", title: "Set Up New Vet", conditions: ["AnyPets": ["Yes"], "MoveDistance": ["Long Distance", "Cross-Country"]], isSubTask: true, parentTask: "PET_OPTIONS"),
    Task(id: "CANCEL_YOGA", title: "Cancel Yoga Membership", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "Yoga": ["Yes"]], isSubTask: true, parentTask: "FITNESS_OPTIONS"),
    Task(id: "CANCEL_GYM", title: "Cancel Gym Membership", conditions: ["MoveDistance": ["Long Distance", "Cross-Country"], "Gym": ["Yes"]], isSubTask: true, parentTask: "FITNESS_OPTIONS")
]

// MARK: - Test Scenarios

func repeatString(_ str: String, _ count: Int) -> String {
    return String(repeating: str, count: count)
}

print(repeatString("=", 70))
print("MINI-ASSESSMENT FLOW TEST")
print(repeatString("=", 70))

// Scenario: Family with kids, long distance move
let coreAssessment: [String: Any] = [
    "selectedMoveDate": "true",
    "MoveDistance": "Long Distance",
    "WhosMoving": "Family",
    "AnyPets": "No",
    "HireMovers": "Hire Movers"
]

print("\n[Phase 1] Initial Task Generation (core assessment only)")
print(repeatString("-", 50))

var initialTasks: [String] = []
var skippedSubTasks: [String] = []

for task in taskCatalog {
    // Skip sub-tasks during initial generation
    if task.isSubTask {
        skippedSubTasks.append(task.id)
        print(">> SKIP (sub-task): \(task.title)")
        continue
    }

    let conditions: [String: Any] = task.conditions
    if TaskConditionParser.evaluateConditions(conditions, against: coreAssessment) {
        initialTasks.append(task.id)
        print("[+] GENERATE: \(task.title)")
    } else {
        print("[-] EXCLUDE: \(task.title)")
    }
}

print("\nInitial tasks generated: \(initialTasks.count)")
print("Sub-tasks deferred: \(skippedSubTasks.count)")

// Verify correct behavior
var passed = 0
var failed = 0

// Should include CHILDREN_OPTIONS (WhosMoving: Family)
if initialTasks.contains("CHILDREN_OPTIONS") {
    print("[PASS] CHILDREN_OPTIONS correctly included"); passed += 1
} else {
    print("[FAIL] CHILDREN_OPTIONS should be included"); failed += 1
}

// Should NOT include PET_OPTIONS (AnyPets: No)
if !initialTasks.contains("PET_OPTIONS") {
    print("[PASS] PET_OPTIONS correctly excluded"); passed += 1
} else {
    print("[FAIL] PET_OPTIONS should be excluded"); failed += 1
}

// Should NOT include sub-tasks yet
if !initialTasks.contains("BEGIN_SCHOOL_TRANSFER") {
    print("[PASS] BEGIN_SCHOOL_TRANSFER correctly deferred"); passed += 1
} else {
    print("[FAIL] BEGIN_SCHOOL_TRANSFER should be deferred"); failed += 1
}

print("\n[Phase 2] After Children Mini-Assessment Completes")
print(repeatString("-", 50))

// User completes children mini-assessment
let childrenAnswers: [String: Any] = [
    "SchoolAgeChildren": "2",
    "ChildrenUnder5": "0"
]

// Combined assessment (core + mini-assessment answers)
var combinedAssessment = coreAssessment
for (key, value) in childrenAnswers {
    combinedAssessment[key] = value
}

print("Combined assessment now has: \(combinedAssessment.keys.sorted())")

// Generate sub-tasks for CHILDREN_OPTIONS
var generatedSubTasks: [String] = []

for task in taskCatalog {
    guard task.isSubTask, task.parentTask == "CHILDREN_OPTIONS" else { continue }

    let conditions: [String: Any] = task.conditions
    if TaskConditionParser.evaluateConditions(conditions, against: combinedAssessment) {
        generatedSubTasks.append(task.id)
        print("[+] GENERATE: \(task.title)")
    } else {
        print("[-] EXCLUDE: \(task.title)")
    }
}

print("\nSub-tasks generated after mini-assessment: \(generatedSubTasks.count)")

// Should now include school tasks
if generatedSubTasks.contains("BEGIN_SCHOOL_TRANSFER") {
    print("[PASS] BEGIN_SCHOOL_TRANSFER now generated"); passed += 1
} else {
    print("[FAIL] BEGIN_SCHOOL_TRANSFER should now be generated"); failed += 1
}

if generatedSubTasks.contains("NEW_SCHOOL_ENROLLMENT") {
    print("[PASS] NEW_SCHOOL_ENROLLMENT now generated"); passed += 1
} else {
    print("[FAIL] NEW_SCHOOL_ENROLLMENT should now be generated"); failed += 1
}

print("\n[Phase 3] Fitness Mini-Assessment (different user)")
print(repeatString("-", 50))

let fitnessAnswers: [String: Any] = [
    "Yoga": "Yes",
    "Gym": "No",
    "Pilates": "No"
]

var combinedWithFitness = coreAssessment
for (key, value) in fitnessAnswers {
    combinedWithFitness[key] = value
}

var fitnessSubTasks: [String] = []

for task in taskCatalog {
    guard task.isSubTask, task.parentTask == "FITNESS_OPTIONS" else { continue }

    let conditions: [String: Any] = task.conditions
    if TaskConditionParser.evaluateConditions(conditions, against: combinedWithFitness) {
        fitnessSubTasks.append(task.id)
        print("[+] GENERATE: \(task.title)")
    } else {
        print("[-] EXCLUDE: \(task.title)")
    }
}

// Should include CANCEL_YOGA (Yoga: Yes), exclude CANCEL_GYM (Gym: No)
if fitnessSubTasks.contains("CANCEL_YOGA") {
    print("[PASS] CANCEL_YOGA correctly generated"); passed += 1
} else {
    print("[FAIL] CANCEL_YOGA should be generated"); failed += 1
}

if !fitnessSubTasks.contains("CANCEL_GYM") {
    print("[PASS] CANCEL_GYM correctly excluded"); passed += 1
} else {
    print("[FAIL] CANCEL_GYM should be excluded"); failed += 1
}

print("\n" + repeatString("=", 70))
print("RESULTS: \(passed)/\(passed + failed) passed")
if failed > 0 {
    print("[ERROR] \(failed) TESTS FAILED")
    exit(1)
} else {
    print("[SUCCESS] ALL TESTS PASSED")
    print("\nFlow verified:")
    print("  1. Initial generation skips sub-tasks")
    print("  2. Mini-assessment completion triggers sub-task generation")
    print("  3. Sub-tasks evaluated against combined assessment data")
    exit(0)
}
