// TaskGenerationService.swift
// Peezy iOS - Task Generation from Catalog
//
// LAST UPDATED: 2026-02-12
//
// Generates personalized task list by reading the taskCatalog collection,
// evaluating each task's conditions against the user's assessment data,
// and writing matching tasks to users/{uid}/tasks/.
//
// CONDITION FORMAT: Conditions are stored as maps { fieldName: [acceptableValues] }
// See TaskCatalogSchema.swift for full documentation.
//
// CHANGES (2026-02-12):
//   - Removed mini-assessment task creation (consolidated into main assessment)
//   - Removed isSubTask/parentTask skip logic
//   - Removed dead fields: pageKey, isAssessmentTask, isSubTask, parentTask, priority
//   - Task document ID = taskId from catalog (e.g., "BOOK_MOVERS")
//   - Debug prints gated behind #if DEBUG

import Foundation
import FirebaseFirestore

class TaskGenerationService {

    private let db = Firestore.firestore()

    /// Generates tasks for a user based on their assessment
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - assessment: Dictionary containing user's assessment data
    ///   - moveDate: The user's move date
    /// - Returns: Number of tasks generated
    @MainActor
    func generateTasksForUser(
        userId: String,
        assessment: [String: Any],
        moveDate: Date
    ) async throws -> Int {
        #if DEBUG
        print("🚀 TASK GEN: Starting for user \(userId)")
        print("📅 TASK GEN: Move date is \(moveDate), today is \(DateProvider.shared.now)")
        #endif

        // 1. Fetch all tasks from taskCatalog
        let catalogSnapshot = try await db.collection("taskCatalog").getDocuments()
        #if DEBUG
        print("📚 Found \(catalogSnapshot.documents.count) tasks in catalog")
        print("🔍 ASSESSMENT DATA FOR CONDITIONS:")
        for (key, value) in assessment.sorted(by: { $0.key < $1.key }) {
            print("   • \(key): \(value) (type: \(type(of: value)))")
        }
        #endif

        var tasksToCreate: [[String: Any]] = []

        // 2. Evaluate each task's conditions
        for document in catalogSnapshot.documents {
            let taskData = document.data()
            let taskTitle = taskData["title"] as? String ?? "Unknown"

            // Get conditions — stored as { fieldName: [acceptableValues] }
            let conditions = taskData["conditions"] as? [String: Any]

            #if DEBUG
            print("🔍 Evaluating: '\(taskTitle)' conditions: \(conditions ?? [:])")
            #endif

            // Evaluate conditions against user's assessment
            let conditionPassed = TaskConditionParser.evaluateConditions(conditions, against: assessment)

            if conditionPassed {
                // Calculate due date based on urgency
                let urgencyPercentage = (taskData["urgencyPercentage"] as? NSNumber)?.intValue ?? 50

                let dueDate = calculateDueDate(
                    moveDate: moveDate,
                    urgencyPercentage: urgencyPercentage
                )

                #if DEBUG
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MMM d"
                print("✅ '\(taskTitle)' → due: \(dateFormatter.string(from: dueDate)) (urgency: \(urgencyPercentage))")
                #endif

                // Build user task document
                var userTask: [String: Any] = [
                    "id": document.documentID,              // e.g., "BOOK_MOVERS"
                    "taskId": taskData["taskId"] ?? document.documentID,
                    "title": taskData["title"] ?? "",
                    "desc": taskData["desc"] ?? "",
                    "category": taskData["category"] ?? "custom",
                    "actionCategory": taskData["actionCategory"] ?? "",
                    "actionType": taskData["actionType"] ?? "off-app",
                    "urgencyPercentage": urgencyPercentage,
                    "estHours": taskData["estHours"] ?? 0,
                    "tips": taskData["tips"] ?? "",
                    "whyNeeded": taskData["whyNeeded"] ?? "",
                    "conditions": taskData["conditions"] ?? [:],
                    "dueDate": Timestamp(date: dueDate),
                    "status": "Upcoming",
                    "userId": userId,
                    "createdAt": Timestamp(date: Date()),
                ]

                // Copy workflowId only if present (workflow tasks only)
                if let workflowId = taskData["workflowId"] as? String {
                    userTask["workflowId"] = workflowId
                }

                tasksToCreate.append(userTask)
            } else {
                #if DEBUG
                print("❌ Skipping: '\(taskTitle)'")
                #endif
            }
        }

        #if DEBUG
        print("📋 TASK GEN: \(tasksToCreate.count) tasks matched conditions")
        #endif

        // 3. Batch write tasks to user's collection
        let batch = db.batch()
        let userTasksRef = db.collection("users").document(userId).collection("tasks")

        for taskData in tasksToCreate {
            let docId = taskData["id"] as? String ?? UUID().uuidString
            let taskRef = userTasksRef.document(docId)
            batch.setData(taskData, forDocument: taskRef)
        }

        // 4. Commit batch
        do {
            try await batch.commit()
            #if DEBUG
            print("✅ TASK GEN: Wrote \(tasksToCreate.count) tasks to Firestore")
            #endif
        } catch {
            #if DEBUG
            print("❌ TASK GEN FAILED: \(error)")
            #endif
            throw error
        }

        let totalTasks = tasksToCreate.count
        #if DEBUG
        print("✨ TASK GEN: Complete — \(totalTasks) tasks generated")
        #endif

        return totalTasks
    }

    // MARK: - Due Date Calculation

    /// Calculates task due date based on urgency percentage
    /// Higher percentage (90+) = MORE urgent = do it EARLY (within first 10% of timeline)
    /// Lower percentage (10) = LESS urgent = can wait (90% into timeline)
    /// - Parameters:
    ///   - moveDate: User's move date
    ///   - urgencyPercentage: Task urgency (1-99)
    /// - Returns: Calculated due date
    private func calculateDueDate(
        moveDate: Date,
        urgencyPercentage: Int
    ) -> Date {
        let today = Calendar.current.startOfDay(for: DateProvider.shared.now)
        let moveDateStart = Calendar.current.startOfDay(for: moveDate)
        let totalDays = Calendar.current.dateComponents([.day], from: today, to: moveDateStart).day ?? 0

        // Guard against past/same-day moves
        guard totalDays > 0 else { return today }

        // HIGH urgency (90+) = do it EARLY (within first 10% of timeline)
        // LOW urgency (10) = can wait (90% into timeline)
        let daysFromNow = Double(totalDays) * (1.0 - Double(urgencyPercentage) / 100.0)
        var dueDate = Calendar.current.date(byAdding: .day, value: Int(daysFromNow), to: today) ?? moveDate

        // Never schedule in the past
        if dueDate < today {
            dueDate = today
        }

        return dueDate
    }
}
